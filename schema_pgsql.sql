-- This assumes default Supabase configuration:
--  * everything below goes into `public` schema
--  * there is `auth` schema with `users` table

-- Reference data
CREATE TABLE jsons (
    name TEXT PRIMARY KEY,
    json JSONB NOT NULL
);

CREATE TABLE icons (
    name TEXT PRIMARY KEY,
    icon BYTES
)

CREATE FUNCTION delete_current_user() RETURNS void
SECURITY DEFINER
LANGUAGE sql AS $$
  DELETE FROM auth.users WHERE id = auth.uid();
$$;

-- Additional user data
CREATE TABLE profiles (
    uid UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    FOREIGN KEY (uid)
        REFERENCES auth.users(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE FUNCTION create_profile_for_new_user() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.profiles (uid, name)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$;

CREATE TRIGGER create_profile_for_new_user_trigger
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION create_profile_for_new_user();




-- Allow adding friends; friendship is bi-directional
CREATE TABLE friends (
    name1 TEXT NOT NULL,
    name2 TEXT NOT NULL,
    PRIMARY KEY (name1, name2),
    FOREIGN KEY (name1)
        REFERENCES profiles(name)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    FOREIGN KEY (name2)
        REFERENCES profiles(name)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT cannot_befriend_oneself CHECK ( name1 <> name2 )
);

CREATE FUNCTION sort_friends_row() RETURNS TRIGGER AS $$
    BEGIN
        NEW.name1 := LEAST(NEW.name1, NEW.name2);
        NEW.name2 := GREATEST(NEW.name1, NEW.name2);
        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;

-- This way it won't be possible to have the same friendship twice
CREATE TRIGGER sort_friends_row_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON friends
    FOR EACH ROW
    EXECUTE FUNCTION sort_friends_row();

CREATE POLICY "can_befriend_others" ON friends 
    AS PERMISSIVE 
    FOR ALL 
    USING (
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.name = friends.name1 AND profiles.uid = auth.uid()
    )
    OR
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.name = friends.name2 AND profiles.uid = auth.uid()
    )
);

CREATE OR REPLACE FUNCTION find_friends_by_prefix(start TEXT)
RETURNS TABLE(name TEXT)
SECURITY DEFINER
LANGUAGE sql AS $$
    SELECT name FROM profiles
    WHERE LOWER(name) LIKE LOWER(CONCAT(start, '%'))
    AND uid <> auth.uid();
$$;




-- Remember gaming sessions
CREATE TABLE sessions (
    id UUID PRIMARY KEY
);

CREATE TABLE user_sessions (
    uid UUID PRIMARY KEY,
    sid UUID NOT NULL,
    FOREIGN KEY (uid)
        REFERENCES users(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    FOREIGN KEY (sid)
        REFERENCES sessions(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE FUNCTION remove_empty_sessions() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
    DELETE FROM sessions s WHERE NOT EXISTS (
        SELECT 1 FROM user_sessions us WHERE us.sid = s.id
    );
    RETURN NULL;
$$;

CREATE TRIGGER remove_empty_sessions_trigger
    AFTER DELETE ON user_sessions
    EXECUTE FUNCTION remove_empty_sessions();
